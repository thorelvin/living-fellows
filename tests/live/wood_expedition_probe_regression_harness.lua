-- SPDX-License-Identifier: MIT
-- Probe ownership/orchestration contracts. Actual effects need the GL client.
local Probe = SCRealSandboxHarnessProbes.SCWoodExpeditionProbe
local checks = 0
local function expect(value, why)
    checks = checks + 1
    if not value then error("wood live probe: " .. why) end
end
local calls, pending = {}, true
local original = {}
function original:getX() return 12041.65 end
function original:getY() return 6747.67 end
function original:getZ() return 0 end
local car = { sqlId = 46, zone = { id = "saved-parking" }, vehicle = original }
local crew = { { id = "original-scarlet", actor = original } }
SurvivorCompanion = {
    ExpeditionPrototype = {
        startWoodCollection = function(records, options)
            calls[#calls + 1] = { records = records, options = options }
            if pending then return false, "forest_scan_pending" end
            return true
        end,
        current = function() return nil end,
        requestReturn = function() error("probe must never order return") end,
        finishAtPlayer = function() error("probe must never complete mission") end,
    },
}
getFileWriter = function() return nil end
local function fixture(mode)
    return { config = {}, phase = "wood_expedition_dispatch",
        woodExpedition = { mode = mode, quantity = mode == "drive" and 2 or 1,
            crew = crew, car = car, startedAt = 0, trees = {}, ground = {} } }
end
local rows = {}
local function result(status, name) rows[name] = status end
local function check(name, value) result(value and "PASS" or "FAIL", name) return value end
local H = fixture("walk")
local function phase(name) H.phase = name end
Probe.step(H, 1, check, result, phase)
expect(H.phase == "wood_expedition_dispatch" and rows.wood_probe_public_dispatch == nil,
    "bounded asynchronous metadata query remains pending")
pending = false
Probe.step(H, 2, check, result, phase)
expect(H.phase == "wood_expedition_mission" and calls[2].records == crew,
    "dispatch actual saved roster using ordinary public API")
expect(calls[2].options.request.quantity == 1 and calls[2].options.travelMode == "road"
    and calls[2].options.vehicleSqlId == nil, "walking uses one raw log and ordinary road mode")
H = fixture("drive")
Probe.step(H, 3, check, result, phase)
expect(calls[3].options.request.quantity == 2 and calls[3].options.travelMode == "drive"
    and calls[3].options.vehicleSqlId == 46 and calls[3].options.parkingZoneId == "saved-parking",
    "driving uses two raw logs and saved car46 without replacement")

local tree = { getObjectIndex = function() return 0 end }
local square = { getTree = function() return tree end }
local effects = { trees = { target = { tree = tree, square = square } } }
expect(Probe._tests.treeEffects(effects) == 0, "unchanged tree is not a successful chop")
square.getTree = function() return nil end
expect(Probe._tests.treeEffects(effects) == 1, "native removal is required")
local owner, other = {}, {}
local item = { id = "exact-log", kind = "Base.Log", owner = other }
function item:getContainer() return self.owner end
SurvivorCompanion.GameplayUtil = {
    itemType = function(value) return value.kind end,
    itemStableId = function(value) return value.id end,
    inventoryContains = function(container, value) return container == owner and value == item end,
}
SurvivorCompanion.BaseLife = {
    storage = function(id) return id == "storage" and {} end,
    resolveContainer = function() return owner end,
}
local receipt = { id = "exact-log", storageId = "storage", stored = true }
expect(not Probe._tests.storageOwned(SurvivorCompanion, receipt, item),
    "stored flag without actual item owner cannot pass")
item.owner = owner
expect(Probe._tests.storageOwned(SurvivorCompanion, receipt, item), "exact physical membership and owner both required")
item.id = "same-type-replacement"
expect(not Probe._tests.storageOwned(SurvivorCompanion, receipt, item), "same-type replacement cannot satisfy receipt")
expect(Probe._tests.count({ a = {}, b = {} }) == 2, "native identity evidence maps count all entries")

-- An equipment fixture is an explicit clone-only input. It must first inspect
-- real production permissions and must leave native loot to the real worker.
local created, items, rows = {}, {}, {}
local function inventory(capacity)
    local value = { items = {}, capacity = capacity or 30 }
    function value:getItems() return self.items end
    function value:getFreeCapacity() return self.capacity end
    return value
end
local actor = { id = "saved-scarlet", root = inventory(18) }
function actor:getWornItem() return self.worn end
function actor:setWornItem(_, value) self.worn = value end
function actor:isEquippedClothing(value) return self.worn == value end
local function native(kind)
    local value = { kind = kind, id = kind .. ":" .. (#created + 1), data = {}, broken = false }
    function value:getContainer() return self.owner end
    function value:isBroken() return self.broken end
    function value:getTreeDamage() return 35 end
    function value:getInventory() return self.bag end
    function value:getWeightReduction() return 80 end
    function value:canBeEquipped() return "native:back-location" end
    if kind == "Base.Bag_BigHikingBag" then value.bag = inventory(22) end
    return value
end
instanceItem = function(kind)
    expect(kind == "Base.Axe" or kind == "Base.Bag_BigHikingBag", "fixture never creates logs or trees")
    local value = native(kind)
    created[#created + 1] = value
    return value
end
local tools = { id = "saved:tools", category = "tools", container = inventory() }
rows = { tools }
local mock = {
    GameplayUtil = {
        itemType = function(value) return value.kind end,
        itemStableId = function(value) return value.id end,
        itemHasTag = function(value) return value.kind == "Base.Axe" end,
        itemWeight = function(value) return value.kind == "Base.Axe" and 3 or 1.5 end,
        listSize = function(values) return #values end,
        listGet = function(values, index) return values[index + 1] end,
        modData = function(value) return value.data end,
        inventory = function(value) return value.root end,
        inventoryContains = function(container, value)
            for _, candidate in ipairs(container and container.items or {}) do if candidate == value then return true end end
            return false
        end,
        addItem = function(container, value)
            container.items[#container.items + 1], value.owner = value, container
            return value
        end,
        carryLoad = function(value) return 9.07 + (value.worn and 1.5 or 0), 18 end,
    },
    LoggingWork = { inventoryEntries = function(value)
        local entries = {}
        for _, itemValue in ipairs(value.root.items) do entries[#entries + 1] = { item = itemValue, source = value.root } end
        return entries
    end },
    ExpeditionWood = { reserved = function(value) return value.reserved == true end },
    PersonalItems = { isProtected = function(value) return value.protected == true end },
    WorkTransport = { hasRoom = function(container) return #container.items < container.capacity end },
    BaseLife = {
        storageRows = function() return rows end,
        resolveContainer = function(row) return row.container end,
        storage = function(id) for _, row in ipairs(rows) do if row.id == id then return row end end end,
        withdrawable = function(row) return row.withdrawals ~= false end,
        storageAcceptsDeposit = function(row) return row.deposits ~= false end,
        availableCountExact = function() return 1 end,
    },
}
local supplied = { crew = { { actor = actor } } }
local function fixtureCheck(name, value) expect(value == true, name) return value end
local function noResult() end
local initial = Probe._tests.equipmentSurvey(mock, actor, noResult)
expect(initial.complete and initial.usable == 0 and #initial.supplies == 1,
    "empty saved Tools supply is surveyed before creating fixture equipment")
expect(Probe._tests.stockEquipment(mock, { config = {} }, supplied, initial, fixtureCheck, noResult)
    and #created == 0 and #tools.container.items == 0,
    "default flag never stocks any gear")
expect(Probe._tests.projectedCarry(mock, actor, native("Base.Axe"), false) == false,
    "9.07 existing load plus real axe and log exceeds native Strength allowance")
expect(Probe._tests.stockEquipment(mock, { config = { wood_expedition_stock_equipment = "true" } },
    supplied, initial, fixtureCheck, noResult), "explicit fixture can stock missing native equipment")
expect(#created == 2 and created[1].kind == "Base.Axe" and created[2].kind == "Base.Bag_BigHikingBag"
    and supplied.fixtureAxe == tools.container.items[1] and supplied.fixtureBag == actor.worn,
    "one native axe is in existing Tools, and one actual bag is worn only for capacity")
expect(created[1].owner == tools.container and not mock.GameplayUtil.inventoryContains(actor.root, created[1]),
    "probe does not hand the axe to the actor or bypass production withdrawal")
local surveyed = Probe._tests.equipmentSurvey(mock, actor, noResult)
expect(surveyed.usable == 1 and surveyed.supplyAxe == created[1], "production supply survey recognizes the same usable stocked axe")
expect(Probe._tests.stockEquipment(mock, { config = { wood_expedition_stock_equipment = "true" } },
    supplied, surveyed, fixtureCheck, noResult) and #created == 2,
    "already usable stock and adequate bag capacity cannot create duplicate fixture equipment")
tools.container = nil
expect(not Probe._tests.equipmentSurvey(mock, actor, noResult).complete,
    "unloaded production supplies remain unknown rather than being declared axe-free")
tools.container = inventory()
tools.withdrawals = false
local deniedAxe = native("Base.Axe")
mock.GameplayUtil.addItem(tools.container, deniedAxe)
local deniedSurvey = Probe._tests.equipmentSurvey(mock, actor, noResult)
expect(deniedSurvey.usable == 0 and #deniedSurvey.supplies == 0,
    "withdrawal-forbidden stock cannot qualify as usable equipment or a fixture destination")

-- Tools may be full in an unchanged player save. Use the first admitted
-- existing production supply category; never retag or enlarge a container.
actor.worn, actor.root.items = nil, {}
tools.withdrawals, tools.container = true, inventory()
tools.container.capacity = 0
local general = { id = "saved:general", category = "general", container = inventory() }
local construction = { id = "saved:construction", category = "construction", container = inventory() }
local weapons = { id = "saved:weapons", category = "weapons", container = inventory() }
local blockedWeapons = { id = "saved:weapons-denied", category = "weapons", deposits = false, container = inventory() }
rows = { general, blockedWeapons, construction, weapons, tools }
local fallback = Probe._tests.equipmentSurvey(mock, actor, noResult)
expect(#fallback.supplies == 4 and fallback.supplies[1].storage == tools
    and fallback.supplies[2].storage == weapons and fallback.supplies[3].storage == construction
    and fallback.supplies[4].storage == general,
    "fixture supply priority matches production and excludes deposit-forbidden targets")
local before = #created
local fallbackFixture = { crew = { { actor = actor } } }
expect(Probe._tests.stockEquipment(mock, { config = { wood_expedition_stock_equipment = "true" } },
    fallbackFixture, fallback, fixtureCheck, noResult), "full Tools can fall through to admitted existing camp supplies")
expect(#created == before + 2 and fallbackFixture.fixtureAxeStorage == weapons
    and #tools.container.items == 0 and #weapons.container.items == 1
    and weapons.container.items[1] == fallbackFixture.fixtureAxe,
    "one axe is stocked in Weapons after full Tools; original chosen storage owns its later loan return")

local cleanupCalls, quietRows = {}, {}
local quietHarness = { config = {}, clearZombiesNear = function(target, radius)
    cleanupCalls[#cleanupCalls + 1] = { actor = target, radius = radius }
    return 3
end }
local quietFixture = { crew = crew }
local siteMission = { scout = { wood = {}, phase = "wood_working",
    vehicle = { state = "parked_at_site" } } }
local function quietResult(_, name, detail) quietRows[#quietRows + 1] = { name = name, detail = detail } end
expect(not Probe._tests.maintainQuietSite(quietHarness, quietFixture, siteMission, 0, quietResult)
    and #cleanupCalls == 0 and #quietRows == 0,
    "default quiet-site option never touches the world or records a removal")
quietHarness.config.wood_expedition_quiet_site = "true"
siteMission.scout.phase, siteMission.scout.vehicle.state = "outbound", "driving_out"
expect(not Probe._tests.maintainQuietSite(quietHarness, quietFixture, siteMission, 0, quietResult)
    and #cleanupCalls == 0, "explicit quiet fixture leaves outbound driving and roadside danger intact")
siteMission.scout.vehicle.state = "unloading_site"
expect(Probe._tests.maintainQuietSite(quietHarness, quietFixture, siteMission, 0, quietResult)
    and cleanupCalls[1].actor == original and cleanupCalls[1].radius == 60
    and quietFixture.quietRemoved == 3 and quietFixture.quietCalls == 1,
    "existing cleanup helper receives the actual actor and 60-tile radius only on arrival at site")
expect(not Probe._tests.maintainQuietSite(quietHarness, quietFixture, siteMission, 999, quietResult)
    and #cleanupCalls == 1, "site clearing is bounded to one call per second")
siteMission.scout.phase, siteMission.scout.vehicle = "wood_working", nil
expect(Probe._tests.maintainQuietSite(quietHarness, quietFixture, siteMission, 1000, quietResult)
    and #cleanupCalls == 2 and quietFixture.quietRemoved == 6
    and string.find(quietRows[2].detail, "total_removed=6", 1, true),
    "walking site work also permits explicit cleanup and logs its exact cumulative removal count")
siteMission.scout.phase, siteMission.scout.vehicle = "inbound", { state = "driving_home" }
expect(not Probe._tests.maintainQuietSite(quietHarness, quietFixture, siteMission, 2000, quietResult)
    and #cleanupCalls == 2, "homeward travel and return danger remain untouched")

-- Select saved people only. The optional three-person reproduction never
-- manufactures a body, restores health, moves a person, or replaces their AI.
local function person(id, name, inside, health, recruited)
    local value = { id = id, name = name, inside = inside, health = health or 100, recruited = recruited ~= false }
    function value:isDead() return false end
    function value:isBridgeHealthy() return true end
    function value:getBodyDamage() return self end
    function value:getOverallBodyHealth() return self.health end
    function value:getNumPartsBleeding() return 0 end
    return { id = id, actor = value }
end
local saved = { person("c", "Tess Nolan", true), person("z", "Scarlet Stewart", true),
    person("a", "Jill Kelvin", true), person("hurt", "Hurt", true, 20),
    person("outside", "Outside", false), person("stranger", "Stranger", true, 100, false) }
local selection = { Registry = { records = function() return saved end },
    Commands = { peek = function(value) return { recruited = value.recruited } end },
    GameplayUtil = { nameOf = function(value) return value.name end },
    BaseLife = { isInside = function(value) return value.inside end } }
local one, three = Probe._tests.selectCrew(selection, 1), Probe._tests.selectCrew(selection, 3)
expect(#one == 1 and one[1].actor == saved[2].actor, "default still selects the actual saved Scarlet only")
expect(#three == 3 and three[1].actor == saved[2].actor
    and three[2].actor == saved[3].actor and three[3].actor == saved[1].actor,
    "three-person crew keeps Scarlet lead and selects two healthy recruited camp records deterministically")
saved[2].actor.inside = false
expect(#Probe._tests.selectCrew(selection, 3) == 0 and #Probe._tests.selectCrew(selection, 1) == 1,
    "three-person fixture refuses Scarlet away from camp while preserving legacy single-person admission")
saved[2].actor.inside = true

-- Read-only primary0 visibility evidence works with the old diagnostic bridge.
-- Primary/car movement is a comparison guard, never a request to reposition.
local squares, journal, screenshots, nativeCalls = {}, {}, {}, 0
local function entity(x, y)
    local value = { x = x, y = y, z = 0, alpha = 1, target = 1, direction = "S", engine = false }
    function value:getX() return self.x end
    function value:getY() return self.y end
    function value:getZ() return self.z end
    function value:getDir() return self.direction end
    function value:getAlpha(index) expect(index == 0, "alpha is explicitly for primary player0") return self.alpha end
    function value:getTargetAlpha(index) expect(index == 0, "target alpha is explicitly for primary player0") return self.target end
    function value:getCurrentSquare() return self.square end
    function value:getDoRender() return true end
    function value:getSqlId() return self.id end
    function value:getCurrentSpeedKmHour() return self.speed or 0 end
    function value:isEngineRunning() return self.engine end
    function value:isRemovedFromWorld() return false end
    local square = { visible = true }
    function square:getZ() return 0 end
    function square:getCanSee(index) expect(index == 0, "square visibility uses primary0") return self.visible end
    function square:isCouldSee() return true end
    function square:isSeen() return true end
    value.square = square
    squares[math.floor(x) .. ":" .. math.floor(y)] = square
    return value
end
local primary, firstCar, secondCar, movingCar = entity(100, 100), entity(101, 100), entity(102, 100), entity(103, 100)
firstCar.id, secondCar.id, movingCar.id, movingCar.speed = 46, 47, 48, 5
firstCar.z, secondCar.z = 0.01, -0.001
local nativeCars = { firstCar, secondCar, movingCar }
local carSet = { size = function() return #nativeCars end }
local loadedVehicleCalls = 0
getCell = function() return {
    getGridSquare = function(_, x, y, z) return z == 0 and squares[x .. ":" .. y] or nil end,
    getVehicles = function() return carSet end,
} end
getFileWriter = function() return { writeln = function(_, line) journal[#journal + 1] = line end, close = function() end } end
getSpecificPlayer = function(index) return index == 0 and primary or nil end
getPlayerScreenWidth = function() return 1280 end
getCore = function() return { getScreenWidth = function() return 1280 end,
    TakeFullScreenshot = function(_, name) screenshots[#screenshots + 1] = name end } end
local restore = { status = "waiting", pending = true }
local visibilityTime = 0
getTimestampMs = function() return visibilityTime end
local named = 0
SurvivorCompanion = {
    Registry = selection.Registry, Commands = selection.Commands, BaseLife = selection.BaseLife,
    Names = { displayName = function(value) named = named + 1 return value.name or "Known primary" end },
    Vehicle = { loadedVehicles = function() loadedVehicleCalls = loadedVehicleCalls + 1 return nativeCars end },
    ExpeditionPrototype = { current = function() return nil end },
    ViewSession = { owner = function() return nil end, primaryRestoreDiagnostic = function() return restore end },
}
SCSplitScreenProbe = { releaseDiagnostics = function() return "frameIsPrimary=true" end }
local observed = { mode = "walk", crew = three, dispatchedAt = 1 }
Probe._tests.snapshotVisibility(SurvivorCompanion, observed, primary)
Probe._tests.captureVisibility(SurvivorCompanion, observed, "before")
expect(#observed.visibility.cars == 2 and observed.visibility.cars[1].before.visible
    and observed.visibility.cars[2].before.visible, "native vehicle list retains both stationary visible cars and excludes moving traffic")
expect(carSet.get == nil and loadedVehicleCalls == 1,
    "native vehicle Set has no get method: probe consumes the production loadedVehicles Lua-array adapter")
expect(observed.visibility.cars[1].before.canonical == firstCar.square
    and observed.visibility.cars[2].before.canonical == secondCar.square,
    "native physics Z0.01 and negative epsilon use the authoritative square floor0 for admission and canonical lookup")
expect(string.find(table.concat(journal, "\n"), "reason=moving", 1, true),
    "every bounded native vehicle inventory entry explains its admission or rejection")
expect(named >= 3 and string.find(table.concat(journal, "\n"), "visibility:before", 1, true)
    and string.find(table.concat(journal, "\n"), "alpha0=1", 1, true)
    and string.find(table.concat(journal, "\n"), "canonicalSame=true", 1, true),
    "before journal includes Names names, explicit alpha0 and canonical square identity without new native fields")
local fact = Probe._tests.visibilityFacts(firstCar)
firstCar.square = {}
expect(not Probe._tests.visibilityFacts(firstCar).visible, "stale actor square cannot qualify as a canonical visibility witness")
firstCar.square = fact.square
firstCar.square.visible = false
expect(Probe._tests.visibilityFacts(firstCar, true).visible and not Probe._tests.visibilityFacts(firstCar).visible,
    "rendered seen car can remain visible without square canSee, while actor visibility remains strict")
firstCar.couldSeeIntersectedSquare = function() return false end
expect(not Probe._tests.visibilityFacts(firstCar, true).visible,
    "public intersected-square negative visibility prevents a car witness")
firstCar.couldSeeIntersectedSquare = function() return true end
local actualSquare = firstCar.square
firstCar.square = { getZ = function() return 0 end, isSeen = function() return true end }
expect(Probe._tests.visibilityFacts(firstCar, true).visible and not Probe._tests.visibilityFacts(firstCar).visible,
    "car anchor offsets are logged without falsely rejecting an otherwise rendered seen car; actor identity remains strict")
firstCar.square = actualSquare
firstCar.square.visible = true
local evidenceRows = {}
local function evidenceResult(status, name, detail) evidenceRows[name] = { status = status, detail = detail } end
local probeHarness = { config = { run_id = "visibility-fixture" } }
Probe._tests.observeSoloVisibility(probeHarness, observed, evidenceResult)
expect(observed.visibility.frames == 0 and #screenshots == 0, "no postsolo frame is counted until the deferred primary restore applies")
restore.status, restore.pending = "applied", false
for _ = 1, 2 do Probe._tests.observeSoloVisibility(probeHarness, observed, evidenceResult) end
expect(#screenshots == 1 and string.find(screenshots[1], "postsolo-frame2", 1, true)
    and not evidenceRows.wood_probe_primary_car_visible_46, "early solo PNG and facts precede any car assertion")
SCSplitScreenProbe.debugPrimaryCutawaySample = function()
    nativeCalls = nativeCalls + 1 return "legacyFields=true;newCacheDiagnostic=available"
end
firstCar.alpha, firstCar.target = 0, 0
firstCar.z, secondCar.z = -0.001, 0.01
Probe._tests.observeWitnessMovement(observed)
expect(not observed.visibility.cars[1].moved and not observed.visibility.cars[2].moved,
    "suspension and physics epsilon changes within0.05 do not mark stationary ground cars as moved")
visibilityTime = 100
for _ = 3, 12 do Probe._tests.observeSoloVisibility(probeHarness, observed, evidenceResult) end
expect(#screenshots == 2 and not observed.visibility.done and nativeCalls > 0
    and not evidenceRows.wood_probe_primary_car_visible_46,
    "frame12 PNG and optional native samples precede assertions when high refresh has allowed only100ms for asynchronous lighting")
visibilityTime = 1499
Probe._tests.observeSoloVisibility(probeHarness, observed, evidenceResult)
expect(#screenshots == 2 and not observed.visibility.done,
    "final comparison cannot run before1500ms of ordinary restored rendering")
visibilityTime = 1500
Probe._tests.observeSoloVisibility(probeHarness, observed, evidenceResult)
expect(#screenshots == 3 and observed.visibility.done
    and string.find(screenshots[3], "postsolo-settled", 1, true),
    "settled PNG and final assertions require both12frames and1500ms")
expect(evidenceRows.wood_probe_primary_car_visible_46.status == "FAIL"
    and evidenceRows.wood_probe_primary_car_visible_47.status == "PASS",
    "an unchanged initially visible car losing primary alpha fails while the second visible car is also checked")
local function skipped(status) expect(status == "SKIP", "legitimate change is explicitly skipped, never a false pass or failure") end
primary.x = primary.x + 1
expect(Probe._tests.compareVisibleCars(observed, skipped) == 0, "moving the primary invalidates all fixed-point comparisons")
primary.x = primary.x - 1
firstCar.x, secondCar.x = firstCar.x + 1, secondCar.x + 1
expect(Probe._tests.compareVisibleCars(observed, skipped) == 0, "moving a car invalidates its original witness")
firstCar.x, secondCar.x = firstCar.x - 1, secondCar.x - 1
firstCar.engine = true
Probe._tests.observeWitnessMovement(observed)
firstCar.engine = false
expect(observed.visibility.cars[1].moved == true,
    "a car used during the trip remains ineligible even if it returns to its exact original point")
observed.visibility.cars[2].moved = true
expect(Probe._tests.compareVisibleCars(observed, skipped) == 0,
    "remembered movement prevents a returned car from masquerading as an unchanged parked witness")
observed.visibility.cars[1].before.visible, observed.visibility.cars[2].before.visible = false, false
expect(Probe._tests.compareVisibleCars(observed, skipped) == 0, "zero initial witnesses yields SKIP rather than visibility success")
nativeCars = {}
for index = 1, 512 do nativeCars[index] = index % 2 == 0 and firstCar or secondCar end
local journalStart = #journal
Probe._tests.snapshotVisibility(SurvivorCompanion, observed, primary)
local inspected = 0
for index = journalStart + 1, #journal do
    if string.find(journal[index], "visibility:vehicle-inventory", 1, true) then inspected = inspected + 1 end
end
expect(inspected == 256 and observed.visibility.vehicleInventorySize == 512 and #observed.visibility.cars == 8,
    "native enumeration inspects at most256 loaded objects and retains at most8 car witnesses")

-- The three-person reproduction walks the real observer into the actual
-- kitchen only after ordinary return/storage. No private placement helper is
-- allowed; exercise the real south-wall discovery helper with native-action
-- callback stand-ins, and keep unrelated queued work untouched.
expect(not Probe._tests.kitchenRequested({ config = {} })
    and not Probe._tests.kitchenRequested({ config = { wood_expedition_crew_size = "1" } })
    and Probe._tests.kitchenRequested({ config = { wood_expedition_crew_size = "3" } }),
    "kitchen walk is enabled for optional crew3 only; default crew1 flow stays unchanged")
local kitchenRoom = { getName = function() return "kitchen" end }
local kitchenSquares, wallFlags = {}, 0
IsoFlagType = { cutN = "north", cutW = "west" }
local function kitchenSquare(x, y, inside, wall)
    local value = { x = x, y = y }
    function value:getZ() return 0 end
    function value:getRoom() return inside and kitchenRoom or nil end
    function value:getProperties() return { has = function(_, flag) return wall and flag == "north" end } end
    function value:TreatAsSolidFloor() return true end
    function value:hasFloor() return true end
    function value:isSolid() return false end
    function value:isSolidTrans() return false end
    function value:HasTree() return false end
    function value:getVehicleContainer() return nil end
    function value:getDoorTo() return nil end
    function value:getWindowTo() return nil end
    function value:getCanSee() return true end
    function value:isCouldSee() return true end
    function value:isSeen() return true end
    function value:getPlayerCutawayFlag() return wallFlags end
    kitchenSquares[x .. ":" .. y] = value
    return value
end
local targetSquare = kitchenSquare(12035, 6746, true)
kitchenSquare(12035, 6747, true)
local southWall = kitchenSquare(12035, 6748, false, true)
local outsideSquare = kitchenSquare(12035, 6749, false)
SurvivorCompanion.GameplayUtil = { gridSquare = function(x, y, z)
    return z == 0 and kitchenSquares[x .. ":" .. y] or nil
end }
getCell = function() return { getGridSquare = function(_, x, y, z)
    return SurvivorCompanion.GameplayUtil.gridSquare(x, y, z)
end } end
primary.x, primary.y, primary.z, primary.square = 12035.5, 6749.5, 0, outsideSquare
primary.setX = function() error("kitchen probe must walk; no placement") end
primary.setY = primary.setX
primary.setZ = primary.setX
SCSplitScreenProbe.debugPrimaryCutawaySample = function()
    return "primaryRoom=kitchen;frameRoom=kitchen;targetBits=" .. wallFlags
end
local unrelated = { owner = "another action" }
local nativeQueue, pathCalls = { queue = { unrelated } }, {}
function nativeQueue:removeFromQueue(action)
    for index, value in ipairs(self.queue) do if value == action then table.remove(self.queue, index) return end end
end
ISTimedActionQueue = {
    add = function(action) nativeQueue.queue[#nativeQueue.queue + 1] = action end,
    getTimedActionQueue = function(value) expect(value == primary, "queue belongs to the same original human") return nativeQueue end,
    clear = function() error("kitchen probe must never clear unrelated actions") end,
}
ISPathFindAction = { pathToLocationF = function(_, value, x, y, z)
    local action = { character = value, target = { x, y, z }, action = {}, stopped = 0 }
    function action:setOnComplete(callback) self.complete = callback end
    function action:setOnFail(callback) self.failed = callback end
    function action:forceStop() self.stopped = self.stopped + 1 end
    pathCalls[#pathCalls + 1] = action
    return action
end }
local kitchenFixture = { mode = "walk", primary = primary, crew = three, startedAt = 0,
    trees = {}, ground = {}, latestStepAt = 2000 }
local kitchenH = { player = primary, config = { run_id = "kitchen-fixture", wood_expedition_crew_size = "3" },
    woodExpedition = kitchenFixture }
local wallTests = SCRealSandboxHarnessProbes.SCViewCutawayProbe._tests
local actualWallAt, scannedAnchors = wallTests.wallAt, 0
wallTests.wallAt = function(...)
    scannedAnchors = scannedAnchors + 1
    return actualWallAt(...)
end
visibilityTime = 2000
local started, routeReason = Probe._tests.startKitchenRoute(kitchenH, kitchenFixture, 2000, evidenceResult)
wallTests.wallAt = actualWallAt
expect(started and scannedAnchors == 81 and kitchenFixture.kitchen.wall.square == southWall,
    "bounded9x9 actual wallAt search finds the south wall belonging to the verified target kitchen: " .. tostring(routeReason))
local ownedPath = pathCalls[1]
expect(#pathCalls == 1 and ownedPath.character == primary and ownedPath.target[1] == 12035.5
    and ownedPath.target[2] == 6746.5 and ownedPath.target[3] == 0,
    "stock native player path targets the exact verified kitchen point")
expect(primary.y == 6749.5 and nativeQueue.queue[1] == unrelated and nativeQueue.queue[2] == ownedPath,
    "queueing a walk does not teleport the player or remove unrelated queued actions")
expect(not Probe._tests.kitchenPose(primary, kitchenFixture.kitchen), "outside pose cannot count as kitchen arrival")
kitchenH.phase = "wood_expedition_kitchen_walk"
local function kitchenPhase(name) kitchenH.phase = name end
local function kitchenCheck(name, okay, detail) evidenceResult(okay and "PASS" or "FAIL", name, detail) return okay end
Probe.step(kitchenH, 2010, kitchenCheck, evidenceResult, kitchenPhase)
expect(kitchenH.phase == "wood_expedition_kitchen_walk", "no observation begins before native path completion")
-- Simulate what the native path callback observes, without invoking any probe
-- placement API or considering this a substitute for the real GL walk.
primary.x, primary.y, primary.square = 12035.5, 6746.5, targetSquare
nativeQueue:removeFromQueue(ownedPath)
ownedPath.complete()
wallFlags = 1
Probe.step(kitchenH, 2050, kitchenCheck, evidenceResult, kitchenPhase)
expect(kitchenH.phase == "wood_expedition_kitchen_capture" and kitchenFixture.kitchen.stage == "observing",
    "native completion plus actual same-room/point verification starts observation")
local kitchenPNGStart = #screenshots
visibilityTime = 2100
for _ = 1, 120 do Probe._tests.observeKitchen(kitchenH, kitchenFixture, evidenceResult) end
expect(#screenshots == kitchenPNGStart + 3 and not kitchenFixture.kitchen.done
    and string.find(screenshots[kitchenPNGStart + 1], "kitchen-frame2", 1, true)
    and string.find(screenshots[kitchenPNGStart + 2], "kitchen-frame12", 1, true)
    and string.find(screenshots[kitchenPNGStart + 3], "kitchen-frame120", 1, true),
    "kitchen frames2/12/120 each capture actual wall PNG and facts, while120 fast frames cannot bypass1500ms")
visibilityTime = 3550
Probe._tests.observeKitchen(kitchenH, kitchenFixture, evidenceResult)
expect(kitchenFixture.kitchen.done and evidenceRows.wood_probe_kitchen_south_cutaway.status == "PASS"
    and evidenceRows.wood_probe_kitchen_pixels_require_review.status == "SKIP",
    "settled native south bit is checked after120frames plus1500ms and pixels still require review")
expect(string.find(table.concat(journal, "\n"), "wall=12035,6748,0", 1, true)
    and string.find(table.concat(journal, "\n"), "frameRoom=kitchen;targetBits=1", 1, true),
    "journal retains exact verified south wall, primary room, frame room and native target bits")
Probe.step(kitchenH, 3560, kitchenCheck, evidenceResult, kitchenPhase)
expect(kitchenH.phase == "finish" and not kitchenFixture.kitchen.active and ownedPath.stopped == 0,
    "successful observation completes without cancelling the already finished path")
local interrupted = { mode = "walk", primary = primary, crew = three, latestStepAt = 3600 }
expect(Probe._tests.startKitchenRoute(kitchenH, interrupted, 3600, evidenceResult), "second owned path fixture queues normally")
local secondPath = pathCalls[2]
Probe._tests.cleanupKitchen(interrupted, true)
expect(secondPath.stopped == 1 and #nativeQueue.queue == 1 and nativeQueue.queue[1] == unrelated,
    "failure cleanup stops/removes only the exact probe-owned path and preserves unrelated work")

-- Fast BaseWatch control reuses the same real walking/capture helpers. A
-- negative native-counter fixture must reach the kitchen and retain failures;
-- it must never heal/place residents or replace ordinary Decision.
local viewProbe = SCRealSandboxHarnessProbes.SCViewCutawayProbe
local fact = viewProbe._tests.quickOwnFact("visibilityNativeCounter0=17;lightingRawCounter0=19;visibilityRawCanSee=true;visibilityRawCouldSee=false")
expect(fact.counter == 17 and fact.rawCounter == 19 and fact.canSee and not fact.couldSee,
    "quick diagnostics distinguish Java publication from raw native counters and exact own-square visibility")
local watch, slot1, ownerMode, watchStarts, watchCloses, frozenCounter = nil, nil, nil, 0, 0, nil
local watchStartAttempts = 0
local originalDecision = function() return "ordinary AI" end
SurvivorCompanion.Decision = { update = originalDecision }
SurvivorCompanion.BaseLife.active = function() return {} end
SurvivorCompanion.BaseWork = { cancel = function() error("quick fixture must not cancel resident work") end }
SurvivorCompanion.Downtime = { cancel = function() error("quick fixture must not cancel downtime") end }
SurvivorCompanion.Commands.issue = function() error("quick fixture must not change resident commands") end
SurvivorCompanion.ViewSession.owner = function() return ownerMode end
SurvivorCompanion.BaseWatch = {
    current = function() return watch end,
    candidates = function() return { saved[2] } end,
    start = function(id)
        expect(id == saved[2].id, "quick watch uses the exact healthy saved public candidate")
        watchStartAttempts = watchStartAttempts + 1
        if watchStartAttempts == 1 then return false, "leader_finishing_outdoor_work" end
        watchStarts = watchStarts + 1
        watch, slot1, ownerMode = { leaderActor = saved[2].actor }, saved[2].actor, "base_watch"
        return true
    end,
    cancelBeforeDeparture = function()
        watchCloses = watchCloses + 1
        watch, slot1, ownerMode = nil, nil, nil
        restore.status, restore.pending = "applied", false
        frozenCounter = math.floor(visibilityTime / 100)
        return true
    end,
}
getSpecificPlayer = function(index) if index == 0 then return primary else return slot1 end end
SCSplitScreenProbe.debugSetPrimaryViewRestoreMode = function(mode) return mode == "B" end
SCSplitScreenProbe.debugPrimaryCutawaySample = function()
    local counter = frozenCounter or math.floor(visibilityTime / 100)
    return "visibilityNativeCounter0=" .. counter .. ";lightingRawCounter0=" .. counter
        .. ";visibilityRawCanSee=" .. tostring(frozenCounter == nil)
        .. ";visibilityRawCouldSee=" .. tostring(frozenCounter == nil)
        .. ";lightingThreadAlive=true;lightingWaitingForMain=true;primaryRoom=kitchen;frameRoom=kitchen;targetBits=" .. wallFlags
end
local renderCallbacks = {}
Events = { OnPostRender = {
    Add = function(callback) renderCallbacks[#renderCallbacks + 1] = callback end,
    Remove = function(callback)
        for index, value in ipairs(renderCallbacks) do if value == callback then table.remove(renderCallbacks, index) return end end
    end,
} }
local function renderQuick(frames, now)
    visibilityTime = now
    for _ = 1, frames do
        for _, callback in ipairs(renderCallbacks) do callback() end
    end
end
nativeCars = {}
primary.x, primary.y, primary.square = 12035.5, 6749.5, outsideSquare
local carVantageSquare = kitchenSquare(12035, 6753, false)
restore.status, restore.pending, wallFlags = "idle", false, 0
local quickH = { player = primary, phase = "view_cutaway_setup", phaseStartedAt = 2000,
    config = { run_id = "quick-watch-fixture", view_cutaway_quick_watch = "true", view_cutaway_restore_mode = "B" } }
local function quickPhase(name, now) quickH.phase, quickH.phaseStartedAt = name, now end
visibilityTime = 2000
viewProbe.step(quickH, 2000, kitchenCheck, evidenceResult, quickPhase)
expect(quickH.phase == "view_cutaway_quick_baseline" and #renderCallbacks == 1,
    "opt-in quick fixture starts with one healthy resident rather than comprehensive two-indoor-resident requirements")
renderQuick(12, 3500)
viewProbe.step(quickH, 3500, kitchenCheck, evidenceResult, quickPhase)
expect(quickH.phase == "view_cutaway_quick_start" and watchStarts == 0 and watchStartAttempts == 1,
    "transient public outdoor-work rejection waits after healthy baseline without cancelling the resident job")
viewProbe.step(quickH, 3600, kitchenCheck, evidenceResult, quickPhase)
expect(watchStartAttempts == 1, "pending resident eligibility retries are bounded to once per second")
visibilityTime = 4500
viewProbe.step(quickH, 4500, kitchenCheck, evidenceResult, quickPhase)
expect(quickH.phase == "view_cutaway_quick_join" and watchStarts == 1 and watchStartAttempts == 2,
    "the same resident may start normally after its transient job completes")
viewProbe.step(quickH, 4550, kitchenCheck, evidenceResult, quickPhase)
renderQuick(12, 6100)
viewProbe.step(quickH, 6100, kitchenCheck, evidenceResult, quickPhase)
expect(quickH.phase == "view_cutaway_quick_close", "actual joined leader settles before close")
visibilityTime = 6150
viewProbe.step(quickH, 6150, kitchenCheck, evidenceResult, quickPhase)
expect(quickH.phase == "view_cutaway_quick_solo" and watchCloses == 1 and watch == nil,
    "public cancelBeforeDeparture performs the single owned close")
renderQuick(12, 6200)
renderQuick(1, 7700)
viewProbe.step(quickH, 7750, kitchenCheck, evidenceResult, quickPhase)
expect(quickH.phase == "view_cutaway_quick_kitchen_walk", "settled solo release proceeds to the ordinary player kitchen path")
local quickPath = pathCalls[#pathCalls]
primary.x, primary.y, primary.square = 12035.5, 6746.5, targetSquare
nativeQueue:removeFromQueue(quickPath)
quickPath.complete()
viewProbe.step(quickH, 7800, kitchenCheck, evidenceResult, quickPhase)
expect(quickH.phase == "view_cutaway_quick_kitchen_capture", "native walk callback confirms a second actual primary position")
renderQuick(120, 7900)
renderQuick(1, 9300)
viewProbe.step(quickH, 9350, kitchenCheck, evidenceResult, quickPhase)
expect(quickH.phase == "view_cutaway_quick_car_walk" and #renderCallbacks == 1
    and evidenceRows.view_quick_primary_own_visibility_after_walk.status == "FAIL"
    and evidenceRows.view_quick_primary_counter_after_walk.status == "FAIL",
    "frozen kitchen visibility remains a failure while the probe continues to the ordinary outdoor car walk")
local carPath = pathCalls[#pathCalls]
expect(carPath ~= quickPath and carPath.target[1] == 12035.5 and carPath.target[2] == 6753.5,
    "car revisit uses the actual verified standable outdoor target and a fresh stock path")
primary.x, primary.y, primary.square = 12035.5, 6753.5, carVantageSquare
nativeQueue:removeFromQueue(carPath)
carPath.complete()
viewProbe.step(quickH, 9400, kitchenCheck, evidenceResult, quickPhase)
expect(quickH.phase == "view_cutaway_quick_car_capture", "actual outdoor arrival starts the parked-car revisit observation")
renderQuick(120, 9500)
renderQuick(1, 10900)
viewProbe.step(quickH, 10950, kitchenCheck, evidenceResult, quickPhase)
expect(quickH.phase == "finish" and #renderCallbacks == 0
    and evidenceRows.view_quick_primary_own_visibility_at_car.status == "FAIL"
    and evidenceRows.view_quick_primary_counter_at_car.status == "FAIL",
    "frozen native sight/counters remain failures after the third ordinary primary position; car samples still complete")
expect(SurvivorCompanion.Decision.update == originalDecision and watchStarts == 1 and watchCloses == 1
    and nativeQueue.queue[1] == unrelated and quickPath.stopped == 0 and carPath.stopped == 0,
    "quick BaseWatch fixture preserves ordinary AI, exact owned view lifecycle and unrelated player actions")
expect(string.find(table.concat(journal, "\n"), "lightingThreadAlive=true", 1, true)
    and string.find(table.concat(journal, "\n"), "adjacentKitchen{", 1, true),
    "before/during/after quick journal retains thread scheduling facts and an adjacent verified kitchen sample")

local alternateCalls = {}
SurvivorCompanion.BaseWatch.candidates = function() return { saved[1], saved[2] } end
SurvivorCompanion.BaseWatch.start = function(id)
    alternateCalls[#alternateCalls + 1] = id
    if id == saved[1].id then return false, "leader_finishing_outdoor_work" end
    return true
end
local alternate = { watchStartAt = 12000, frames = 0, mode = "quick-base-watch", leader = saved[1],
    crew = { saved[1] }, helpers = Probe._tests, adjacentKitchen = { x = 12035, y = 6747, z = 0 },
    visibility = { actors = { { id = saved[1].id, actor = saved[1].actor, group = "crew" },
        { id = saved[2].id, actor = saved[2].actor, group = "home" } } } }
expect(viewProbe._tests.quickTryWatch(quickH, alternate, 12000, evidenceResult, quickPhase)
    and #alternateCalls == 2 and alternate.leader.actor == saved[2].actor
    and alternate.visibility.actors[1].group == "home" and alternate.visibility.actors[2].group == "crew",
    "public transient rejection tries another healthy real candidate and updates exact crew/home ownership")
expect(viewProbe._tests.quickTryWatch(quickH, alternate, 13000, evidenceResult, quickPhase)
    and #alternateCalls == 2, "an accepted public watch is never started a second time on a later pulse")
SC_TEST_REPORT = "Wood expedition live probe: " .. checks .. " ownership/orchestration checks passed"
