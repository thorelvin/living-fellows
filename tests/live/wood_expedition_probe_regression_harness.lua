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
SC_TEST_REPORT = "Wood expedition live probe: " .. checks .. " ownership/orchestration checks passed"
