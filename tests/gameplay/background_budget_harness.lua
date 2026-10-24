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
clock = clock + 10000
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
clock = clock + 10000
B.auditOperations(false, allowance(2))
B.reset()
B.create({ x = 20, y = 20, z = 0 }, "Replacement camp")
current = finish(function(budget) return B.auditOperations(false, budget) end, 4)
check(current.stock[1].count == 0, "base reset discards old pending inventory cursor")

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
local recoveryCalls, farmCalls, operationCalls = 0, 0, 0
local maintenanceBase = { id = "maintenance", settings = {}, maintenanceTargets = {} }
SC.BaseLife = { active = function() return maintenanceBase end,
    auditJobRecovery = function() recoveryCalls = recoveryCalls + 1 return false end,
    auditOperations = function()
        operationCalls = operationCalls + 1
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
-- Medical, disabled sorting and disabled routines finish before the cleaning
-- phase; that phase retains its 96-tile quota instead of renewing it forever.
for index = 1, 3 do finish(function(budget) return W.auditMaintenance({}, budget) end, 3) end
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
