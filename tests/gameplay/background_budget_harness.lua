-- SPDX-License-Identifier: MIT
-- Real audit/controllers under a deterministic allowance exhausted mid-scan.
local SC, checks, clock = SurvivorCompanion, 0, 100000
local U, B, W, F, L, FW = SC.GameplayUtil, SC.BaseLife, SC.BaseWork,
    SC.Factions, SC.FactionLife, SC.FactionWorld
local function check(value, message)
    checks = checks + 1
    assert(value, "background budget " .. checks .. ": " .. message)
end
function getTimestampMs() return clock end
function getGameTime() return { getWorldAgeHours = function() return 24 end,
    getTimeOfDay = function() return 12 end } end
U.nowMs = function() return clock end
U.call = function(object, method, ...)
    if object and type(object[method]) == "function" then return object[method](object, ...), true end
    return nil, false
end
U.position = function(object) return object and object.x, object and object.y, object and object.z or 0 end
U.idOf = function(actor) return actor and actor.id end
U.inventory = function(actor) return actor and actor.inventory end
local counters = {}
SC.Performance = { count = function(key) counters[key] = (counters[key] or 0) + 1 end }
local function allowance(units)
    -- Advancing a budget query models an elapsed fake-clock work boundary.
    return function() units = units - 1 return units >= 0 and 0.1 or 0 end
end
local function finish(callback, units)
    local pending, calls, first, reason = true, 0
    while pending and calls < 2000 do
        calls = calls + 1
        first, reason, pending = callback(allowance(units or 4))
    end
    check(not pending, "a positive small allowance eventually completes: " .. tostring(reason)
        .. " items=" .. tostring(counters.base_operations_item))
    return first, reason, calls
end
local function item(id, nested)
    return { id = id, getFullType = function() return "Base.Apple" end,
        getCategory = function() return "Food" end,
        getInventory = function() return nested end }
end
local function inventory(items)
    return { items = items, getItems = function(self) return self.items end }
end

-- Public operations retain the previous complete report while the next
-- container is suspended; no repeated prefix counts and no partial UI data.
B.reset()
local okay, base = B.create({ x = 10, y = 10, z = 0 }, "Budget camp")
check(okay == true, "real base created")
local contents = {}
for index = 1, 5 do contents[index] = item(index) end
local stock = inventory(contents)
base.storages = { { id = "stock", category = "food", container = stock } }
B.resolveContainer = function(storage) return storage.container end
local published = B.auditOperations(true)
check(published and published.stock[1].count == 5, "initial complete count published")
for index = 6, 10 do contents[index] = item(index) end
local starts = counters.base_operations_started
clock = clock + 5000
local quiet, _, quietPending = B.auditOperations(false, allowance(4))
check(not quietPending and quiet.stock[1].count == 5 and counters.base_operations_started == starts,
    "unaudited external change waits beyond the previous five-second fallback")
clock = clock + 4999
quiet, _, quietPending = B.auditOperations(false, allowance(4))
check(not quietPending and quiet.stock[1].count == 5 and counters.base_operations_started == starts,
    "unchanged revision reuses the full report through 9999 ms")
clock = clock + 1
local old, reason, pending = B.auditOperations(false, allowance(3))
check(pending == true and old.stock[1].count == 5,
    "exhausted item scan keeps prior published count")
local before = counters.base_operations_item or 0
local ui, _, uiPending = B.auditOperations(false)
check(uiPending and ui.stock[1].count == 5 and counters.base_operations_item == before,
    "summary-style read neither drains nor publishes pending scan")
local current = finish(function(budget) return B.auditOperations(false, budget) end, 4)
check(current.stock[1].count == 10 and (counters.base_operations_item or 0) == 15,
    "resumed container counts each item once and publishes atomically")
do
    local originalCopy, reportCopies = SC.StableValue.copyStrict, 0
    SC.StableValue.copyStrict = function(value, options)
        if type(value) == "table" and value.baseId == base.id and value.stock then
            reportCopies = reportCopies + 1
        end
        return originalCopy(value, options)
    end
    local cached, cachedReason, cachedPending = B.auditOperations(false, allowance(4), false)
    check(cached == nil and cachedReason == nil and not cachedPending and reportCopies == 0,
        "background cache hit skips the unused operations report copy")
    contents[11] = item(11)
    clock = clock + 10000
    local report, waiting, backgroundPending = B.auditOperations(false, allowance(3), false)
    check(report == nil and waiting == "base_operations_pending" and backgroundPending and reportCopies == 0,
        "a yielding background refresh skips copying the prior report")
    local completed = finish(function(budget) return B.auditOperations(false, budget, false) end, 4)
    check(completed == nil and reportCopies == 0, "a completed background refresh skips the report copy")
    local publicRead = B.auditOperations(false)
    check(publicRead.stock[1].count == 11 and reportCopies == 1,
        "a public read still sees the newly published complete count")
    publicRead.stock[1].count = 0
    check(B.auditOperations(false).stock[1].count == 11 and reportCopies == 2,
        "a caller can still modify its own report without altering the published count")
    SC.StableValue.copyStrict = originalCopy
end
clock = clock + 10000
B.auditOperations(false, allowance(2))
B.reset()
B.create({ x = 20, y = 20, z = 0 }, "Replacement camp")
current = finish(function(budget) return B.auditOperations(false, budget) end, 4)
check(current.stock[1].count == 0, "base reset discards old pending inventory cursor")

do
    local camp = B.active()
    local food, medical = inventory({item(101)}), inventory({})
    local foodRow = {id = "tracked-food", category = "food", x = camp.core.x, y = camp.core.y,
        z = camp.core.z, container = food}
    camp.storages = {foodRow, {id = "tracked-medicine", category = "medical", container = medical}}
    for index = 1, 9 do medical.items[index] = item(index) end
    local prior = B.auditOperations(true)
    local revision, starts = B.stockRevision(), counters.base_operations_started
    local unrelated = inventory({})
    check(U.addItem(unrelated, item(102)) ~= nil and B.stockRevision() == revision,
        "adding to an unrelated container does not dirty the camp report")
    check(U.transferItemVerified(unrelated, medical, unrelated.items[1]) == true
        and U.addItem(medical, item(103)) ~= nil and B.stockRevision() == revision + 2,
        "a verified transfer and a second addition notify the same tracked stock without a timer")
    local old, waiting, pending = B.auditOperations(false)
    check(old.stock[3].count == 9 and waiting == "base_operations_pending" and pending
        and counters.base_operations_started == starts,
        "a read after a known change serves the old report without starting a scan itself")
    local _, _, refreshing = B.auditOperations(false, allowance(4))
    check(refreshing and counters.base_operations_started == starts + 1,
        "two stock mutations coalesce into one early bounded refresh")
    U.addItem(food, item(104))
    local first = finish(function(budget) return B.auditOperations(false, budget) end, 5)
    check(first.stock[1].count == 1 and first.stock[3].count == 11,
        "stock notification does not restart an already counted prefix")
    local corrected = finish(function(budget) return B.auditOperations(false, budget) end, 5)
    check(corrected.stock[1].count == 2 and corrected.stock[3].count == 11
        and prior.stock[1].count == 1 and prior.stock[3].count == 9
        and counters.base_operations_started == starts + 2,
        "one follow-up publishes the in-flight change and leaves prior snapshots unchanged")
    local stockVersion, storageVersion = B.stockRevision(), B.storageRevision()
    check(U.transferItemVerified(unrelated, medical, medical.items[#medical.items]) and B.stockRevision() == stockVersion,
        "a verified already-moved item does not trigger refresh")
    check(B.setReserve(foodRow.id, nil, 1) and B.storageRevision() == storageVersion + 1
        and B.stockRevision() == stockVersion, "reserve changes invalidate access hints without recounting total stock")
    local encounter, medicalSystem, index = SC.Encounter, SC.Medical, SC.InventoryIndex
    local notified
    SC.Encounter = {noteScavengeContainerChanged = function() error("advisory observer failed") end}
    SC.Medical = {noteInventoryChanged = function(container) notified = container end}
    SC.InventoryIndex = {touchContainer = function(container) return container == medical end}
    check(U.touchInventoryIndex(medical) and notified == medical and B.stockRevision() == stockVersion + 1,
        "the shared hook preserves index results and other notifications if one observer fails")
    SC.Encounter, SC.Medical, SC.InventoryIndex = encounter, medicalSystem, index
    U.addItem(medical, item(105))
    _, _, refreshing = B.auditOperations(false, allowance(5))
    starts = counters.base_operations_started
    check(refreshing and B.setStorageCategory(foodRow.id, "water"), "recategorization interrupts a pending draft")
    old, waiting, pending = B.auditOperations(false)
    check(pending and old.stock[1].count == 2 and old.stock[2].count == 0,
        "structural changes keep the last complete same-camp report visible")
    corrected = finish(function(budget) return B.auditOperations(false, budget) end, 5)
    check(corrected.stock[1].count == 0 and corrected.stock[2].count == 2 and corrected.stock[3].count == 12
        and counters.base_operations_started == starts + 1,
        "a fresh draft publishes the new category without retaining its old count")
    check(B.removeStorage(foodRow.id), "remove the marked stock source")
    stockVersion = B.stockRevision()
    U.addItem(food, item(106))
    check(B.stockRevision() == stockVersion, "removed endpoints no longer dirty camp stock")
    corrected = finish(function(budget) return B.auditOperations(false, budget) end, 5)
    check(corrected.stock[2].count == 0, "removing a marker publishes its missing stock immediately")
    B.reset()
    B.create({ x = 20, y = 20, z = 0 }, "New replacement camp")
    check(B.auditOperations(false) == nil, "a new camp never exposes the previous stock report")
end

-- Real userdata follows the native-list branch. Its contents can disappear
-- between two bounded calls just as an ItemContainer's Java ArrayList does
-- when a secondary chunk unloads. An invalid get is a test failure, even if
-- a production native wrapper would catch the Java exception afterwards.
do
    local firstList, secondList = SC_TEST_JAVA_OBJECT, SC_TEST_BOXED_FLOAT
    check(type(firstList)=="userdata" and type(secondList)=="userdata", "audit lifecycle fixture uses userdata lists")
    local nativeSize,nativeGet,resolve=SC.NativeList.size,SC.NativeList.get,B.resolveContainer
    local rows,gets,sizes,retired={}, {},0,{}
    SC.NativeList.size=function(list)
        if rows[list]~=nil then sizes=sizes+1 return #rows[list] end
        return nativeSize(list)
    end
    SC.NativeList.get=function(list,index)
        local values=rows[list]
        if values~=nil then
            check(not retired[list] and index>=0 and index<#values,
                "retained audit never reads a retired or out-of-range native list cursor")
            gets[list]=(gets[list] or 0)+1
            return values[index+1],true
        end
        return nativeGet(list,index)
    end
    B.resolveContainer=function(storage) return not storage.unloaded and storage.container or nil end
    local function values(count)
        local result={}
        for index=1,count do result[index]=item(index) end
        return result
    end
    local function storage(count)
        B.reset()
        local created,camp=B.create({x=30,y=30,z=0},"Unloading audit camp")
        check(created,"lifecycle audit camp created")
        rows[firstList],rows[secondList],retired[firstList],retired[secondList]=values(count),nil,nil,nil
        gets[firstList],gets[secondList],sizes=0,0,0
        local record={id="native-stock",category="food",container=inventory(firstList)}
        camp.storages={record}
        local report=B.auditOperations(true)
        check(report.stock[1].count==count,"initial native stock audit publishes its complete count")
        clock=clock+10000
        return record
    end

    local marked=storage(6)
    local prior,_,more=B.auditOperations(false,allowance(2))
    check(more and prior.stock[1].count==6 and gets[firstList]==7,
        "one native item prefix is retained only as an unpublished subtotal")
    rows[firstList]={}
    current=finish(function(budget) return B.auditOperations(false,budget) end,4)
    check(current.stock[1].count==0 and gets[firstList]==7,
        "an emptied retained native list drops its old prefix without attempting any stale get")

    marked=storage(8)
    B.auditOperations(false,allowance(3))
    rows[firstList]=values(1)
    current=finish(function(budget) return B.auditOperations(false,budget) end,4)
    check(current.stock[1].count==1 and gets[firstList]==11,
        "a shortened native list restarts that storage subtotal instead of counting its old prefix")

    marked=storage(5)
    B.auditOperations(false,allowance(3))
    rows[secondList],retired[firstList]=values(5),true
    marked.container.items=secondList
    current=finish(function(budget) return B.auditOperations(false,budget) end,4)
    check(current.stock[1].count==5 and gets[firstList]==7 and gets[secondList]==5,
        "a replacement list with unchanged length is read from its own first item and never revisits the retired list")

    marked=storage(7)
    B.auditOperations(false,allowance(3))
    marked.unloaded,retired[firstList],rows[firstList]=true,true,{}
    current=finish(function(budget) return B.auditOperations(false,budget) end,4)
    check(current.stock[1].count==0 and current.unloadedStores==1 and gets[firstList]==9,
        "unloaded storage discards retained native references and partial stock instead of publishing stale inventory")
    clock=clock+10000
    marked.unloaded,rows[secondList],marked.container=false,values(3),inventory(secondList)
    current=finish(function(budget) return B.auditOperations(false,budget) end,4)
    check(current.stock[1].count==3 and current.unloadedStores==0 and gets[secondList]==3,
        "a reloaded storage resolves and audits its new container without resurrecting the retired native list")

    local cap=U.config("baseOperationsStorageItemBudget") or 160
    B.reset()
    local _,camp=B.create({x=40,y=40,z=0},"Capped native audit camp")
    rows[firstList],retired[firstList],gets[firstList],sizes=values(cap+7),nil,0,0
    camp.storages={{id="capped-native-stock",category="food",container=inventory(firstList)}}
    current=B.auditOperations(true)
    check(current.stock[1].count==cap and gets[firstList]==cap and sizes==1,
        "native audit keeps its hard item cap and checks size once per slice, not before every get")
    SC.NativeList.size,SC.NativeList.get,B.resolveContainer=nativeSize,nativeGet,resolve
end

-- Faction resources use an exact nested container cursor and retain the old
-- resource object until all members have been read.
local records = {}
SC.Registry = { byId = function(id) return records[id] end }
local household = { id = "budget-house", name = "Budget house", lifecycle = "settled",
    members = {}, jobs = {}, house = { anchor = { x = 30, y = 30, z = 0 }, interior = {} } }
for index = 1, 2 do
    local id = "member:" .. index
    local bag = inventory({ item(10 * index + 1), item(10 * index + 2) })
    local actor = { id = id, inventory = inventory({ item(10 * index), item(100 + index, bag) }) }
    records[id] = { actor = actor }
    household.members[index] = { key = id, actorId = id, alive = true, role = "resident" }
end
local life = L.initialize(household)
local priorResources = life.resources
local _, _, more = L.auditResources(household, true, allowance(2))
check(more and life.resources == priorResources, "partial nested audit does not replace published resources")
finish(function(budget) return L.auditResources(household, true, budget) end, 3)
check(life.resources ~= priorResources and life.resources.counts.food == 8,
    "member and nested item cursors publish one exact total")
check(counters.faction_resources_item == 8, "resource audit never repeats an exhausted prefix")

-- A top-level pulse must not replay completed production/spawn/event phases
-- when a later phase needs another frame.
F.reset()
local houseCalls, banditCalls, worldCalls, oddballCalls = 0, 0, 0, 0
F.productionPulse = function() houseCalls = houseCalls + 1 return false, "not_due" end
F.banditProductionPulse = function() banditCalls = banditCalls + 1 return false, "not_due" end
SC.FactionWorld = { pulse = function()
    worldCalls = worldCalls + 1
    if worldCalls == 1 then return false, "test_pending", true end
    return false, "world_event_not_due", false
end }
SC.Oddballs = { pulse = function() oddballCalls = oddballCalls + 1 end }
finish(function(budget) return F.pulse({}, clock, budget) end, 1)
check(houseCalls == 1 and banditCalls == 1 and worldCalls == 2 and oddballCalls == 1,
    "continuations resume the exact phase without replaying production or oddball work")

-- Relation enumeration can stop between pairs and candidates, while the
-- due-time/event serial commit happens once after all prerequisites finish.
SC.FactionWorld = FW
local groups, ordered = {}, {}
for index = 1, 4 do
    local group = { id = "world:" .. index, name = "House " .. index,
        lifecycle = "settled", members = {}, history = {} }
    groups[group.id], ordered[index] = group, group
end
F.list = function() return ordered end
F.group = function(id) return groups[id] end
FW.reset()
finish(function(budget) return FW.pulse(24, budget) end, 2)
local exported = FW.export()
local relationCount = 0
for _ in pairs(exported.relations) do relationCount = relationCount + 1 end
check(relationCount == 6 and #exported.news == 0, "all relation pairs complete without early event")
finish(function(budget) return FW.pulse(100, budget) end, 2)
local afterEvent = FW.export()
check(#afterEvent.news == 1, "one due event published after resumed candidate pass")
finish(function(budget) return FW.pulse(100, budget) end, 2)
check(#FW.export().news == 1, "completed event is not duplicated by the next pulse")

-- Maintenance advances a family only once; urgent bounded job recovery still
-- gets called while operations count storage across subsequent frames.
local recoveryCalls, farmCalls, operationCalls, operationReportReads = 0, 0, 0, 0
local maintenanceBase = { id = "maintenance", settings = {}, maintenanceTargets = {} }
SC.BaseLife = { active = function() return maintenanceBase end,
    auditJobRecovery = function() recoveryCalls = recoveryCalls + 1 return false end,
    auditOperations = function(_, _, includeReport)
        operationCalls = operationCalls + 1
        if includeReport ~= false then operationReportReads = operationReportReads + 1 end
        return nil, "operations", operationCalls < 3
    end }
SC.FarmWork = { audit = function() farmCalls = farmCalls + 1 return true, "farm_queued" end }
SC.WorkTransport = nil
local queued = finish(function(budget) return W.auditMaintenance({}, budget) end, 4)
check(queued == true and farmCalls == 1 and operationCalls == 3 and recoveryCalls == 1,
    "maintenance resumes operations without duplicate farm job or repeated same-frame recovery")
maintenanceBase.settings = { autoMaintenance = true, workload = "essential", routines = false }
maintenanceBase.zones = { { kind = "area", x1 = 0, x2 = 20, y1 = 0, y2 = 20, z = 0 } }
SC.BaseLife.dutyResidentIds = function() return {} end
U.gridSquare = function() return { haveStains = function() return false end } end
-- Medical, sorting, and disabled routines finish before cleaning.
local function maintenance(budget) return W.auditMaintenance({}, budget) end
finish(maintenance, 3)
local depositSearches = 0
local markers = { { category = "general" }, { category = "misspelled" }, { category = "tools" } }
maintenanceBase.settings.workload = "balanced"
SC.BaseLife.STORAGE_CATEGORIES = B.STORAGE_CATEGORIES
SC.BaseLife.storageRows = function() return markers end
SC.BaseLife.depositStorageRows = function(category)
    depositSearches = depositSearches + 1
    if not category then return markers end
    for _, marker in ipairs(markers) do
        if marker.category == category then return { marker } end
    end
    return {}
end
local _, sortReason = finish(maintenance, 3)
check(sortReason == "no_sortable_supply" and depositSearches == 1,
    "maintenance finds a valid sorted marker with one registry pass")
check(operationReportReads == 0, "maintenance requests only background report progress")
finish(maintenance, 3)
-- Cleaning retains its 96-tile quota instead of renewing it forever.
local beforeCleaning = counters.base_maintenance_phase_5 or 0
finish(function(budget) return W.auditMaintenance({}, budget) end, 3)
check((counters.base_maintenance_phase_5 or 0) == beforeCleaning + 1,
    "empty cleaning scan eventually completes its retained tile quota")
local roleCalls = 0
SC.BaseLife.auditRoleProduction = function() roleCalls = roleCalls + 1 return false, "none" end
local rearmed = 0
SC.BaseLife.auditJobRecovery = function()
    rearmed = rearmed + 1
    return true, "rearmed_one_job"
end
finish(function(budget) return W.auditMaintenance({}, budget) end, 3)
check(roleCalls == 1 and rearmed == 1,
    "recurrent recoverable work and empty cleaning cannot starve the following family")
check((counters.base_operations_yield or 0) > 0 and (counters.faction_background_yield or 0) > 0,
    "phase exhaustion is visible in performance counters")
SC_TEST_REPORT = "BACKGROUND_BUDGET_PASS checks=" .. checks
